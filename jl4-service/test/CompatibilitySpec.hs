{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for the deployment backwards-compatibility guard
-- ('Compatibility.detectBreakingChanges'). Covers the recursive,
-- direction-aware diff used by the PUT guard (and mirrored client-side
-- in the deploy sidebar): inputs vs outputs, nested records, arrays,
-- enums, required-ness, and whole-function add/remove.
--
-- Also the non-blocking notices for a changed default
-- ('Compatibility.detectDefaultChanges', U2 option B of the bench ruling
-- 2026-11-17), which run every case of @test\/fixtures\/default-change-cases.json@,
-- the file the deploy sidebar's own check runs too.
module CompatibilitySpec (spec) where

import Test.Hspec

import Control.Monad (forM_)
import qualified Data.Aeson as Aeson
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Map.Strict as Map

import L4.FunctionSchema (Parameter (..), Parameters (..))
import Compatibility (FnIface (..), detectBreakingChanges, detectDefaultChanges, ifaceFromSummary)
import ControlPlane (nextDeploymentVersion, parseVersionCounts)
import Types (DefaultChange (..), FunctionSummary (..))

------------------------------------------------------------------------
-- Builders
------------------------------------------------------------------------

-- | A primitive (scalar) parameter of the given JSON type.
prim :: Text -> Parameter
prim t = Parameter t Nothing Nothing [] "" Nothing Nothing Nothing Nothing Nothing Nothing

-- | A string parameter constrained to an enum.
enumP :: [Text] -> Parameter
enumP vs = (prim "string") { parameterEnum = vs }

-- | An object parameter with the given properties and required keys.
objP :: [(Text, Parameter)] -> [Text] -> Parameter
objP props req =
  (prim "object")
    { parameterProperties = Just (Map.fromList props)
    , parameterRequired = Just req
    }

-- | An array parameter with the given element schema.
arrP :: Parameter -> Parameter
arrP item = (prim "array") { parameterItems = Just item }

-- | A function's parameter object (top-level inputs).
ps :: [(Text, Parameter)] -> [Text] -> Parameters
ps props req = MkParameters (Map.fromList props) req

-- | A function interface: name, params, return-type display name,
-- optional structured return schema.
fn :: Text -> Parameters -> Text -> Maybe Parameter -> FnIface
fn = FnIface

-- | No-parameter, BOOLEAN-returning function.
boolFn :: Text -> FnIface
boolFn n = fn n (ps [] []) "BOOLEAN" Nothing

changes :: [FnIface] -> [FnIface] -> [Text]
changes = detectBreakingChanges

shouldBeCompatible :: [FnIface] -> [FnIface] -> Expectation
shouldBeCompatible old new = changes old new `shouldBe` []

mentions :: Text -> [Text] -> Bool
mentions needle = any (Text.isInfixOf needle)

------------------------------------------------------------------------
-- Spec
------------------------------------------------------------------------

spec :: Spec
spec = breakingSpec >> defaultChangesSpec

breakingSpec :: Spec
breakingSpec = describe "Compatibility.detectBreakingChanges" do

  describe "whole functions" do
    it "identical interface is compatible" do
      let f = fn "isEligible" (ps [("age", prim "number")] ["age"]) "BOOLEAN" Nothing
      shouldBeCompatible [f] [f]

    it "adding a new function is compatible" do
      shouldBeCompatible [boolFn "a"] [boolFn "a", boolFn "b"]

    it "removing a function is breaking" do
      let res = changes [boolFn "a", boolFn "b"] [boolFn "a"]
      res `shouldSatisfy` mentions "b"
      res `shouldSatisfy` mentions "removed"

  describe "input parameters" do
    let base = fn "f" (ps [("age", prim "number")] ["age"]) "BOOLEAN" Nothing

    it "adding a new OPTIONAL parameter is compatible" do
      let new = fn "f" (ps [("age", prim "number"), ("nickname", prim "string")] ["age"]) "BOOLEAN" Nothing
      shouldBeCompatible [base] [new]

    it "adding a new REQUIRED parameter is breaking" do
      let new = fn "f" (ps [("age", prim "number"), ("ssn", prim "string")] ["age", "ssn"]) "BOOLEAN" Nothing
      changes [base] [new] `shouldSatisfy` mentions "new required parameter"

    it "removing a parameter is breaking" do
      let new = fn "f" (ps [] []) "BOOLEAN" Nothing
      changes [base] [new] `shouldSatisfy` mentions "removed"

    it "changing a parameter's type is breaking" do
      let new = fn "f" (ps [("age", prim "string")] ["age"]) "BOOLEAN" Nothing
      changes [base] [new] `shouldSatisfy` mentions "type changed from number to string"

    it "changing a parameter's format is breaking" do
      let old = fn "f" (ps [("d", prim "string")] ["d"]) "BOOLEAN" Nothing
          new = fn "f" (ps [("d", (prim "string") { parameterFormat = Just "date" })] ["d"]) "BOOLEAN" Nothing
      changes [old] [new] `shouldSatisfy` mentions "format changed"

    it "tightening an optional parameter to required is breaking" do
      let old = fn "f" (ps [("age", prim "number")] []) "BOOLEAN" Nothing
          new = fn "f" (ps [("age", prim "number")] ["age"]) "BOOLEAN" Nothing
      changes [old] [new] `shouldSatisfy` mentions "is now required"

    it "relaxing a required parameter to optional is compatible" do
      let old = fn "f" (ps [("age", prim "number")] ["age"]) "BOOLEAN" Nothing
          new = fn "f" (ps [("age", prim "number")] []) "BOOLEAN" Nothing
      shouldBeCompatible [old] [new]

    it "renaming a parameter is breaking (removed + new required)" do
      let old = fn "f" (ps [("age", prim "number")] ["age"]) "BOOLEAN" Nothing
          new = fn "f" (ps [("years", prim "number")] ["years"]) "BOOLEAN" Nothing
          res = changes [old] [new]
      res `shouldSatisfy` mentions "removed"
      res `shouldSatisfy` mentions "new required parameter"

  describe "input enums" do
    let withEnum vs = fn "f" (ps [("color", enumP vs)] ["color"]) "BOOLEAN" Nothing

    it "adding an accepted enum value is compatible" do
      shouldBeCompatible [withEnum ["red", "green"]] [withEnum ["red", "green", "blue"]]

    it "removing an accepted enum value is breaking" do
      changes [withEnum ["red", "green", "blue"]] [withEnum ["red", "green"]]
        `shouldSatisfy` mentions "no longer accepts blue"

    it "restricting a free value to a fixed set is breaking" do
      let old = fn "f" (ps [("color", prim "string")] ["color"]) "BOOLEAN" Nothing
      changes [old] [withEnum ["red"]]
        `shouldSatisfy` mentions "restricted to a fixed set"

  describe "nested recursion" do
    it "type change inside a nested record is breaking" do
      let rec t = objP [("zip", prim t)] ["zip"]
          old = fn "f" (ps [("addr", rec "string")] ["addr"]) "BOOLEAN" Nothing
          new = fn "f" (ps [("addr", rec "number")] ["addr"]) "BOOLEAN" Nothing
      changes [old] [new] `shouldSatisfy` mentions "addr.zip"

    it "removing a nested record field is breaking" do
      let old = fn "f" (ps [("addr", objP [("zip", prim "string"), ("city", prim "string")] ["zip", "city"])] ["addr"]) "BOOLEAN" Nothing
          new = fn "f" (ps [("addr", objP [("zip", prim "string")] ["zip"])] ["addr"]) "BOOLEAN" Nothing
      changes [old] [new] `shouldSatisfy` mentions "addr.city"

    it "type change inside array items is breaking" do
      let old = fn "f" (ps [("xs", arrP (prim "number"))] ["xs"]) "BOOLEAN" Nothing
          new = fn "f" (ps [("xs", arrP (prim "string"))] ["xs"]) "BOOLEAN" Nothing
      changes [old] [new] `shouldSatisfy` mentions "xs[]"

    it "adding an optional field to a nested record is compatible" do
      let old = fn "f" (ps [("addr", objP [("zip", prim "string")] ["zip"])] ["addr"]) "BOOLEAN" Nothing
          new = fn "f" (ps [("addr", objP [("zip", prim "string"), ("note", prim "string")] ["zip"])] ["addr"]) "BOOLEAN" Nothing
      shouldBeCompatible [old] [new]

  describe "return type" do
    it "changing the return type display name is breaking" do
      changes [fn "f" (ps [] []) "BOOLEAN" Nothing] [fn "f" (ps [] []) "NUMBER" Nothing]
        `shouldSatisfy` mentions "return type changed from BOOLEAN to NUMBER"

    it "non-deontic to deontic (return type changes) is breaking" do
      changes [fn "f" (ps [] []) "NUMBER" Nothing] [fn "f" (ps [] []) "DEONTIC" Nothing]
        `shouldSatisfy` mentions "return type changed"

    it "missing return schema on both sides only compares the display name" do
      shouldBeCompatible [fn "f" (ps [] []) "BOOLEAN" Nothing] [fn "f" (ps [] []) "BOOLEAN" Nothing]

  describe "return value (output direction is mirrored)" do
    let withRet r = fn "f" (ps [] []) "Result" (Just r)

    it "adding an output field is compatible" do
      let old = withRet (objP [("a", prim "number")] ["a"])
          new = withRet (objP [("a", prim "number"), ("b", prim "string")] ["a"])
      shouldBeCompatible [old] [new]

    it "removing an output field is breaking" do
      let old = withRet (objP [("a", prim "number"), ("b", prim "string")] ["a", "b"])
          new = withRet (objP [("a", prim "number")] ["a"])
      changes [old] [new] `shouldSatisfy` mentions "no longer returned"

    it "an always-present output field becoming optional is breaking" do
      let old = withRet (objP [("a", prim "number")] ["a"])
          new = withRet (objP [("a", prim "number")] [])
      changes [old] [new] `shouldSatisfy` mentions "may now be absent"

    it "widening an output enum (new values) is breaking" do
      let old = withRet (enumP ["ok", "fail"])
          new = withRet (enumP ["ok", "fail", "pending"])
      changes [old] [new] `shouldSatisfy` mentions "may now return new values pending"

    it "narrowing an output enum (fewer values) is compatible" do
      let old = withRet (enumP ["ok", "fail", "pending"])
          new = withRet (enumP ["ok", "fail"])
      shouldBeCompatible [old] [new]

    it "return-value diff is skipped when the return type itself changed" do
      -- Only the (single) return-type message — no spurious output-field noise.
      let old = fn "f" (ps [] []) "A" (Just (objP [("x", prim "number")] ["x"]))
          new = fn "f" (ps [] []) "B" (Just (objP [] []))
      changes [old] [new] `shouldBe` ["f return type changed from A to B"]

  -- The deployment version is stored as a single MAJOR.BREAKING.RUNNING
  -- string and bumped by string-editing it on each deploy (no separate
  -- counter fields). These cover that pure logic.
  describe "deployment version (ControlPlane.nextDeploymentVersion)" do
    it "first deploy is {major}.0.0" do
      nextDeploymentVersion 1 Nothing False `shouldBe` "1.0.0"

    it "non-breaking redeploy bumps only RUNNING" do
      nextDeploymentVersion 1 (Just "1.0.0") False `shouldBe` "1.0.1"

    it "breaking redeploy bumps BREAKING and RUNNING" do
      nextDeploymentVersion 1 (Just "1.0.1") True `shouldBe` "1.1.2"

    it "counters never reset across a service major bump" do
      nextDeploymentVersion 2 (Just "1.1.2") False `shouldBe` "2.1.3"

    it "parses BREAKING/RUNNING out of a version string" do
      parseVersionCounts "3.4.5" `shouldBe` (4, 5)

    it "treats an empty/garbage version as (0, 0)" do
      parseVersionCounts "" `shouldBe` (0, 0)

------------------------------------------------------------------------
-- Changed defaults: the notices (U2 option B)
------------------------------------------------------------------------

-- | One case of the shared fixture: the old and the new parameter schema of
-- one function, and what the redeploy check must answer.
data DefaultCase = DefaultCase
  { caseName     :: Text
  , caseFunction :: Text
  , caseOld      :: Parameters
  , caseNew      :: Parameters
  , caseBreaking :: [Text]
  , caseNotices  :: [DefaultChange]
  }

newtype DefaultCases = DefaultCases [DefaultCase]

instance Aeson.FromJSON DefaultCases where
  parseJSON = Aeson.withObject "cases file" \top -> do
    cs <- top Aeson..: "cases"
    DefaultCases <$> traverse parseCase cs
   where
    parseCase = Aeson.withObject "case" \o -> do
      expect <- o Aeson..: "expect"
      DefaultCase
        <$> o Aeson..: "name"
        <*> o Aeson..: "function"
        <*> o Aeson..: "old"
        <*> o Aeson..: "new"
        <*> expect Aeson..: "breaking"
        <*> expect Aeson..: "notices"

-- | The shared cases. The path is relative to the package directory, where
-- @cabal test@ runs the suite, as the other fixtures are read.
loadDefaultCases :: IO [DefaultCase]
loadDefaultCases = do
  r <- Aeson.eitherDecodeFileStrict "test/fixtures/default-change-cases.json"
  case r of
    Left err -> fail ("test/fixtures/default-change-cases.json: " <> err)
    Right (DefaultCases cs) -> pure cs

-- | A published default of the given JSON value.
withDefault :: Aeson.Value -> Parameter -> Parameter
withDefault v p = p { parameterDefault = Just v }

defaultChangesSpec :: Spec
defaultChangesSpec = describe "Compatibility.detectDefaultChanges" do

  describe "the shared cases (test/fixtures/default-change-cases.json)" do
    cases <- runIO loadDefaultCases
    -- The positive control for the loop below: a fixture that loaded as
    -- nothing would pass every case it never ran.
    it "loaded the cases" do
      length cases `shouldSatisfy` (>= 8)
    forM_ cases \c -> it (Text.unpack c.caseName) do
      let old = fn c.caseFunction c.caseOld "" Nothing
          new = fn c.caseFunction c.caseNew "" Nothing
      detectBreakingChanges [old] [new] `shouldBe` c.caseBreaking
      detectDefaultChanges [old] [new] `shouldBe` c.caseNotices

  describe "beyond the shared cases" do
    let ifaceWith props = fn "f" (ps props []) "BOOLEAN" Nothing

    it "reports a change to or from NOTHING (a null default), which is a default" do
      let old = ifaceWith [("m", withDefault Aeson.Null (prim "number"))]
          new = ifaceWith [("m", withDefault (Aeson.Number 1) (prim "number"))]
      detectDefaultChanges [old] [new]
        `shouldBe` [DefaultChange "f" "m" Aeson.Null (Aeson.Number 1)]

    -- A deployment restarted and not yet compiled is compared from its cached
    -- metadata, which is JSON: the default NOTHING is `"default": null` there.
    it "reports a change from NOTHING read back from the metadata cache" do
      let summary = FunctionSummary "f" "" (ps [("m", withDefault Aeson.Null (prim "number"))] []) "BOOLEAN" Nothing Nothing False Nothing
          cached = Aeson.decode (Aeson.encode summary) :: Maybe FunctionSummary
          new = ifaceWith [("m", withDefault (Aeson.Number 1) (prim "number"))]
      fmap (\c -> detectDefaultChanges [ifaceFromSummary c] [new]) cached
        `shouldBe` Just [DefaultChange "f" "m" Aeson.Null (Aeson.Number 1)]

    it "treats a cached summary with no default key as unknown, not as a change" do
      let summary = FunctionSummary "f" "" (ps [("m", prim "number")] []) "BOOLEAN" Nothing Nothing False Nothing
          cached = Aeson.decode (Aeson.encode summary) :: Maybe FunctionSummary
          new = ifaceWith [("m", withDefault (Aeson.Number 1) (prim "number"))]
      fmap (\c -> detectDefaultChanges [ifaceFromSummary c] [new]) cached `shouldBe` Just []

    it "reports a changed default inside a record held in a list, by its path" do
      let rec d = arrP (objP [("retries", withDefault (Aeson.Number d) (prim "number"))] [])
          old = ifaceWith [("jobs", rec 3)]
          new = ifaceWith [("jobs", rec 5)]
      detectDefaultChanges [old] [new]
        `shouldBe` [DefaultChange "f" "jobs[].retries" (Aeson.Number 3) (Aeson.Number 5)]

    it "reports one notice per changed default, in the old function order, then by input" do
      let g = fn "g" (ps [("b", withDefault (Aeson.Number 0) (prim "number"))] []) "BOOLEAN" Nothing
          g' = fn "g" (ps [("b", withDefault (Aeson.Number 1) (prim "number"))] []) "BOOLEAN" Nothing
          f = ifaceWith [ ("x", withDefault (Aeson.Number 1) (prim "number"))
                        , ("y", withDefault (Aeson.String "a") (prim "string")) ]
          f' = ifaceWith [ ("x", withDefault (Aeson.Number 2) (prim "number"))
                         , ("y", withDefault (Aeson.String "b") (prim "string")) ]
      map (\c -> (c.dcFunction, c.dcInput)) (detectDefaultChanges [g, f] [f', g'])
        `shouldBe` [("g", "b"), ("f", "x"), ("f", "y")]

    it "says nothing of a function present on one side only" do
      let f = ifaceWith [("x", withDefault (Aeson.Number 1) (prim "number"))]
      detectDefaultChanges [f] [] `shouldBe` []
      detectDefaultChanges [] [f] `shouldBe` []

    it "skips an input whose type changed: the type change is the report" do
      let old = ifaceWith [("x", withDefault (Aeson.Number 1) (prim "number"))]
          new = ifaceWith [("x", withDefault (Aeson.String "1") (prim "string"))]
      detectDefaultChanges [old] [new] `shouldBe` []
      detectBreakingChanges [old] [new] `shouldSatisfy` mentions "type changed"

    it "does not call a changed default breaking, so the BREAKING counter cannot move" do
      let old = ifaceWith [("x", withDefault (Aeson.Number 1) (prim "number"))]
          new = ifaceWith [("x", withDefault (Aeson.Number 2) (prim "number"))]
      detectBreakingChanges [old] [new] `shouldBe` []
      length (detectDefaultChanges [old] [new]) `shouldBe` 1

{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for the deployment backwards-compatibility guard
-- ('Compatibility.detectBreakingChanges'). Covers the recursive,
-- direction-aware diff used by the PUT guard (and mirrored client-side
-- in the deploy sidebar): inputs vs outputs, nested records, arrays,
-- enums, required-ness, and whole-function add/remove.
module CompatibilitySpec (spec) where

import Test.Hspec

import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Map.Strict as Map

import L4.FunctionSchema (Parameter (..), Parameters (..))
import Compatibility (FnIface (..), detectBreakingChanges)
import ControlPlane (nextDeploymentVersion, parseVersionCounts)

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

-- | A type with a constructor that carries fields and one that carries none:
-- a oneOf of its names and its tagged constructors (MULLET).
mixedP :: [Text] -> [(Text, Parameter)] -> Parameter
mixedP names tagged =
  (prim "") { parameterOneOf = Just [enumP names, taggedP tagged] }

-- | The tagged constructors of a type whose constructors all carry fields: an
-- object with one key for each and no @required@, as
-- 'L4.FunctionSchema.shapeToParameter' writes it.
taggedP :: [(Text, Parameter)] -> Parameter
taggedP tagged =
  (prim "object") { parameterProperties = Just (Map.fromList tagged) }

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
spec = describe "Compatibility.detectBreakingChanges" do

  -- A type with a constructor that carries fields and one that carries none is
  -- a oneOf of two forms; the gate compares them by their type (MULLET, Meng,
  -- 2026-11-18).
  describe "oneOf forms" do
    let card = objP [("card fee", prim "number")] ["card fee"]
        input p = fn "fee" (ps [("p", p)] ["p"]) "NUMBER" Nothing
        result p = fn "pay" (ps [] []) "Payment" (Just p)
    it "an unchanged oneOf is compatible, as an input and as a result" do
      let m = mixedP ["Cash"] [("Card", card)]
      shouldBeCompatible [input m] [input m]
      shouldBeCompatible [result m] [result m]
    it "adding a form to an input is not breaking" do
      changes [input (enumP ["Cash"])] [input (mixedP ["Cash"] [("Card", card)])] `shouldBe` []
      changes [input (taggedP [("Card", card)])] [input (mixedP ["Cash"] [("Card", card)])] `shouldBe` []
    it "adding a form to a result is breaking, as a name added to a result's enum is (STOWAWAY)" do
      changes [result (enumP ["Cash"])] [result (mixedP ["Cash"] [("Card", card)])]
        `shouldBe` ["pay return value may now return an object"]
      changes [result (taggedP [("Card", card)])] [result (mixedP ["Cash"] [("Card", card)])]
        `shouldBe` ["pay return value may now return a string"]
    it "removing a form is breaking" do
      let m = mixedP ["Cash"] [("Card", card)]
      changes [input m] [input (enumP ["Cash"])] `shouldSatisfy` mentions "fee parameter p no longer accepts an object"
      changes [input m] [input (taggedP [("Card", card)])] `shouldSatisfy` mentions "fee parameter p no longer accepts a string"
      changes [result m] [result (enumP ["Cash"])] `shouldSatisfy` mentions "pay return value no longer returns an object"
    it "a changed form is compared as any node: a name dropped from an input, a field removed from a result" do
      changes [input (mixedP ["Cash", "Cheque"] [("Card", card)])] [input (mixedP ["Cash"] [("Card", card)])]
        `shouldSatisfy` mentions "no longer accepts Cheque"
      changes [result (mixedP ["Cash"] [("Card", card)])] [result (mixedP ["Cash"] [("Card", objP [] [])])]
        `shouldSatisfy` mentions "Card.card fee no longer returned"
      changes [input (mixedP ["Cash"] [("Card", card)])] [input (mixedP ["Cash"] [("Card", card), ("Voucher", objP [] [])])]
        `shouldBe` []

  -- The keys of the tagged object are constructors, compared as an enum's
  -- names are: one added to a result is breaking, one removed from an input is
  -- breaking (STOWAWAY carried to the constructors within the tagged form,
  -- assumed, not ruled; review of #779, 2026-11-19).
  describe "constructors within the tagged object" do
    let reason = objP [("reason", prim "string")] ["reason"]
        court = objP [("court", prim "string")] ["court"]
        input p = fn "decide" (ps [("o", p)] ["o"]) "NUMBER" Nothing
        result p = fn "decide" (ps [] []) "Outcome" (Just p)
    it "a result that gains its first constructor that carries data may now return an object" do
      changes [result (enumP ["Approved", "Rejected"])] [result (mixedP ["Approved", "Rejected"] [("Referred", reason)])]
        `shouldBe` ["decide return value may now return an object"]
    it "a result that has one constructor that carries data and gains a second may now return it" do
      changes [result (mixedP ["Approved", "Rejected"] [("Referred", reason)])]
              [result (mixedP ["Approved", "Rejected"] [("Referred", reason), ("Appealed", court)])]
        `shouldBe` ["decide return value may now return new values Appealed"]
      changes [result (taggedP [("Referred", reason)])] [result (taggedP [("Referred", reason), ("Appealed", court)])]
        `shouldBe` ["decide return value may now return new values Appealed"]
    it "a result that loses a constructor that carries data is not breaking, as a name removed from its enum is not" do
      changes [result (taggedP [("Referred", reason), ("Appealed", court)])] [result (taggedP [("Referred", reason)])]
        `shouldBe` []
    it "an input that loses a constructor that carries data no longer accepts it" do
      changes [input (taggedP [("Referred", reason), ("Appealed", court)])] [input (taggedP [("Referred", reason)])]
        `shouldBe` ["decide parameter o no longer accepts Appealed"]
      changes [input (mixedP ["Approved"] [("Referred", reason), ("Appealed", court)])] [input (mixedP ["Approved"] [("Referred", reason)])]
        `shouldBe` ["decide parameter o no longer accepts Appealed"]
    it "an input that gains a constructor that carries data is not breaking" do
      changes [input (taggedP [("Referred", reason)])] [input (taggedP [("Referred", reason), ("Appealed", court)])]
        `shouldBe` []
    it "a constructor on both sides has its fields compared as a record's" do
      changes [result (taggedP [("Referred", reason)])] [result (taggedP [("Referred", objP [] [])])]
        `shouldBe` ["decide return value Referred.reason no longer returned"]
      changes [input (taggedP [("Referred", objP [] [])])] [input (taggedP [("Referred", reason)])]
        `shouldBe` ["decide has a new required parameter o.Referred.reason"]
      changes [result (taggedP [("Referred", reason)])]
              [result (taggedP [("Referred", objP [("reason", prim "string"), ("note", prim "string")] ["reason"])])]
        `shouldBe` []
    it "a record is still compared by its fields: one gaining an optional result field is compatible" do
      changes [result (objP [("reason", prim "string")] ["reason"])]
              [result (objP [("reason", prim "string"), ("note", prim "string")] ["reason"])]
        `shouldBe` []
      changes [result (objP [("reason", prim "string")] [])]
              [result (objP [("reason", prim "string"), ("note", prim "string")] [])]
        `shouldBe` []

  -- A type whose only constructor is named like it is a record, its fields
  -- alone; given a second constructor, it is an object keyed by constructor.
  -- The gate says the form changed, naming both, where a key-by-key diff said
  -- each field was removed (review of #779, 2026-11-20).
  describe "a type whose only constructor is named like it, given a second" do
    let amount = objP [("amount", prim "number")] ["amount"]
        court = objP [("court", prim "string")] ["court"]
        input p = fn "decide" (ps [("o", p)] ["o"]) "NUMBER" Nothing
        result p = fn "decide" (ps [] []) "Outcome" (Just p)
        fieldsToKeyed = "form changed from an object of its fields (amount) to an object keyed by its constructor (Appealed, Outcome)"
    it "an input's form changed, from its fields to an object keyed by constructor" do
      changes [input amount] [input (taggedP [("Outcome", amount), ("Appealed", court)])]
        `shouldBe` ["decide parameter o " <> fieldsToKeyed]
    it "and one given a second constructor that carries no fields" do
      changes [input amount] [input (mixedP ["Withdrawn"] [("Outcome", amount)])]
        `shouldBe` ["decide parameter o form changed from an object of its fields (amount) to an object keyed by its constructor (Outcome)"]
    it "a result's form changed, and one given a fieldless second may now return a string too" do
      changes [result amount] [result (taggedP [("Outcome", amount), ("Appealed", court)])]
        `shouldBe` ["decide return value " <> fieldsToKeyed]
      changes [result amount] [result (mixedP ["Withdrawn"] [("Outcome", amount)])]
        `shouldBe`
          [ "decide return value form changed from an object of its fields (amount) to an object keyed by its constructor (Outcome)"
          , "decide return value may now return a string" ]
    it "the other way, an input's form changed from an object keyed by constructor to its fields" do
      changes [input (taggedP [("Outcome", amount), ("Appealed", court)])] [input amount]
        `shouldBe` ["decide parameter o form changed from an object keyed by its constructor (Appealed, Outcome) to an object of its fields (amount)"]

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

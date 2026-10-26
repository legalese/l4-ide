{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | What the editor says about a rule that returns @PROVISION OF P, A@, the
-- deprecated alias of @DEONTIC P A@: the same as it says about the rule written
-- the other way, because it is the same type.
--
-- Two places in the editor decided whether a rule was a contract by looking for
-- the word DEONTIC in the printed name of its return type, which the alias does
-- not have: the outline view (a contract is an event, not a function) and the
-- deploy sidebar's flag for the simulation envelope. Both now read the type.
-- The bodies below are @IF@s so that the rule is not a regulative expression
-- on its face, which the outline recognised on its own: it is the return type
-- that has to carry the answer.
module ProvisionEditorSpec (spec) where

import qualified Data.Text as T

import Language.LSP.Protocol.Types (DocumentSymbol (..), SymbolKind (..))

import CheckSource (checkSource)
import qualified L4.Export as Export
import qualified L4.FunctionSchema as FSchema
import LSP.L4.DocumentSymbols (documentSymbols)
import qualified LSP.L4.Inspector as Inspector
import LSP.L4.Rules (TypeCheckResult (..))

import Test.Hspec

-- | A rule that is a contract only by its type, with the return type as given.
contractAs :: T.Text -> T.Text
contractAs returnType = T.unlines
  [ "DECLARE Driver IS ONE OF `the driver`"
  , "DECLARE `Driver Action` IS ONE OF `wear seatbelt`, `drive`"
  , ""
  , "@export default seatbelt requirement"
  , "GIVEN raining IS A BOOLEAN"
  , "GIVETH A " <> returnType
  , "`seatbelt requirement` MEANS"
  , "    IF raining"
  , "    THEN PARTY `the driver` MUST `wear seatbelt` WITHIN 5 HENCE FULFILLED LEST BREACH"
  , "    ELSE PARTY `the driver` MAY `drive`"
  ]

deonticRule, provisionRule :: T.Text
deonticRule = contractAs "DEONTIC Driver `Driver Action`"
provisionRule = contractAs "PROVISION OF Driver, `Driver Action`"

ordinaryRule :: T.Text
ordinaryRule = T.unlines
  [ "@export default is wet"
  , "GIVEN raining IS A BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "`is wet` MEANS raining"
  ]

-- | The outline's symbol kind of each top-level symbol, by name.
outlineKinds :: TypeCheckResult -> [(T.Text, SymbolKind)]
outlineKinds tc = [ (s._name, s._kind) | s <- documentSymbols tc ]

-- | What the language server tells the deploy sidebar about the module's
-- exported functions, as it sends them: name and whether it is a contract.
exported :: TypeCheckResult -> [(T.Text, Bool)]
exported tc =
  [ (f.name, f.isDeontic)
  | f <- map (Inspector.exportedFunctionToSummary (FSchema.declaresFromModule tc.module'))
           (Export.enrichReturnTypes tc.entityInfo (Export.getExportedFunctions tc.module'))
  ]

spec :: Spec
spec = describe "a rule that returns PROVISION OF" do
  describe "in the outline" do
    it "is an event, as is its DEONTIC twin" do
      (_, twin) <- checkSource "provision-outline-deontic" deonticRule
      (_, alias) <- checkSource "provision-outline-provision" provisionRule
      outlineKinds twin `shouldContain` [("seatbelt requirement", SymbolKind_Event)]
      outlineKinds alias `shouldContain` [("seatbelt requirement", SymbolKind_Event)]

    it "leaves a rule that is not a contract a function" do
      (_, tc) <- checkSource "provision-outline-ordinary" ordinaryRule
      outlineKinds tc `shouldContain` [("is wet", SymbolKind_Function)]

  describe "in what the deploy sidebar is told" do
    it "is deontic, as is its DEONTIC twin" do
      (_, twin) <- checkSource "provision-export-deontic" deonticRule
      (_, alias) <- checkSource "provision-export-provision" provisionRule
      exported twin `shouldBe` [("seatbelt requirement", True)]
      exported alias `shouldBe` [("seatbelt requirement", True)]

    it "is not deontic for a rule that is not a contract" do
      (_, tc) <- checkSource "provision-export-ordinary" ordinaryRule
      exported tc `shouldBe` [("is wet", False)]

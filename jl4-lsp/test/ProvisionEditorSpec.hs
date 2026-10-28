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

-- | Rules whose return type has DEONTIC in its name and is not a contract: a
-- type called NonDeonticRule, and a list of contracts. The language server used
-- to look for that word in the upper-cased name of the type and called both
-- deontic; the service asks the type, and says neither is.
lookalikeRule, lookalikeList :: T.Text
lookalikeRule = T.unlines
  [ "DECLARE NonDeonticRule IS ONE OF accepted, declined"
  , ""
  , "@export default a lookalike"
  , "GIVEN raining IS A BOOLEAN"
  , "GIVETH A NonDeonticRule"
  , "`a lookalike` MEANS accepted"
  ]
lookalikeList = T.unlines
  [ "DECLARE Driver IS ONE OF `the driver`"
  , "DECLARE `Driver Action` IS ONE OF `wear seatbelt`, `drive`"
  , ""
  , "@export default lookalike list"
  , "GIVEN raining IS A BOOLEAN"
  , "GIVETH A LIST OF DEONTIC Driver `Driver Action`"
  , "`lookalike list` MEANS EMPTY"
  ]

-- | A rule local to another, with the return type and the body as given.
localRule :: T.Text -> [T.Text] -> T.Text
localRule returnType body = T.unlines $
  [ "DECLARE Driver IS ONE OF `the driver`"
  , "DECLARE `Driver Action` IS ONE OF `wear seatbelt`, `drive`"
  , ""
  , "GIVEN raining IS A BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "`outer` MEANS raining"
  , "  WHERE"
  , "    GIVEN wet IS A BOOLEAN"
  , "    GIVETH A " <> returnType
  , "    `inner` MEANS"
  ] <> map ("        " <>) body

regulativeBody, conditionalBody :: [T.Text]
regulativeBody = ["PARTY `the driver` MUST `wear seatbelt` WITHIN 5 HENCE FULFILLED LEST BREACH"]
conditionalBody =
  [ "IF wet"
  , "THEN PARTY `the driver` MUST `wear seatbelt` WITHIN 5 HENCE FULFILLED LEST BREACH"
  , "ELSE PARTY `the driver` MAY `drive`"
  ]

-- | The outline's symbol kind of each top-level symbol, by name.
outlineKinds :: TypeCheckResult -> [(T.Text, SymbolKind)]
outlineKinds tc = [ (s._name, s._kind) | s <- documentSymbols tc ]

-- | The outline's symbol kind of each symbol one level down, by name.
nestedKinds :: TypeCheckResult -> [(T.Text, SymbolKind)]
nestedKinds tc =
  [ (c._name, c._kind) | s <- documentSymbols tc, Just cs <- [s._children], c <- cs ]

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

    -- Measured on one local rule with a GIVEN and a GIVETH: the typechecker's
    -- entityInfo gave it no type, so the outline has only its body to go on.
    -- These two say what the outline does with a local rule today, for both
    -- spellings; if a local rule is ever given its type, the second is the one
    -- to change, and the spec's Q7 item 3 with it.
    it "is an event when it is local to another rule and its body is regulative, as is its DEONTIC twin" do
      (_, twin) <- checkSource "provision-local-regulative-deontic" (localRule "DEONTIC Driver `Driver Action`" regulativeBody)
      (_, alias) <- checkSource "provision-local-regulative-provision" (localRule "PROVISION OF Driver, `Driver Action`" regulativeBody)
      nestedKinds twin `shouldContain` [("inner", SymbolKind_Event)]
      nestedKinds alias `shouldContain` [("inner", SymbolKind_Event)]

    it "is a function today when it is local to another rule and its body is not regulative on its face, as is its DEONTIC twin" do
      (_, twin) <- checkSource "provision-local-conditional-deontic" (localRule "DEONTIC Driver `Driver Action`" conditionalBody)
      (_, alias) <- checkSource "provision-local-conditional-provision" (localRule "PROVISION OF Driver, `Driver Action`" conditionalBody)
      nestedKinds twin `shouldContain` [("inner", SymbolKind_Function)]
      nestedKinds alias `shouldContain` [("inner", SymbolKind_Function)]

  describe "in what the deploy sidebar is told" do
    it "is deontic, as is its DEONTIC twin" do
      (_, twin) <- checkSource "provision-export-deontic" deonticRule
      (_, alias) <- checkSource "provision-export-provision" provisionRule
      exported twin `shouldBe` [("seatbelt requirement", True)]
      exported alias `shouldBe` [("seatbelt requirement", True)]

    it "is not deontic for a rule that is not a contract" do
      (_, tc) <- checkSource "provision-export-ordinary" ordinaryRule
      exported tc `shouldBe` [("is wet", False)]

    -- A change beyond PROVISION OF: the flag used to be true for any return type
    -- with DEONTIC anywhere in its upper-cased name. It is now the type's own
    -- answer, as the service gives it.
    it "is not deontic for a type that has DEONTIC in its name" do
      (_, tc) <- checkSource "provision-export-lookalike" lookalikeRule
      exported tc `shouldBe` [("a lookalike", False)]

    it "is not deontic for a list of contracts" do
      (_, tc) <- checkSource "provision-export-lookalike-list" lookalikeList
      exported tc `shouldBe` [("lookalike list", False)]

{-# LANGUAGE OverloadedStrings #-}

-- | One type, one text: @#CHECK@ and the inspector the deploy sidebar reads
-- (@l4/getExportedFunctions@) name the inference variables of a polymorphic
-- type alike, skipping a name that is already a type in the printed type. The
-- deploy refuses that @export, because its result is a function, so no
-- deployed @returnType@ prints it.
module DisplayNamesAgreeSpec (spec) where

import Test.Hspec

import Compiler (compileBundle)
import UnresolvedImportSpec (withLog)

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text

import L4.API.VirtualFS (checkWithImports, emptyVFS)
import qualified L4.Export as Export
import L4.FunctionSchema (declaresFromModule)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.TypeCheck (prettyCheckError)
import L4.TypeCheck.Types (CheckError (..), CheckErrorWithContext (..))
import qualified LSP.L4.Inspector as Inspector
import Types (DeploymentMetadata (..), FunctionSummary (..))

-- | A module that declares a type `a` and exports a rule whose result is a
-- function from any type to `a`, which it also asks #CHECK about.
source :: Text
source = Text.unlines
  [ "DECLARE a IS ONE OF approved, rejected"
  , ""
  , "@export Approves whatever it is given"
  , "GIVEN n IS A NUMBER"
  , "`approve` n MEANS GIVEN x YIELD approved"
  , ""
  , "#CHECK `approve` 1"
  ]

spec :: Spec
spec = describe "#CHECK, the inspector and the deployed returnType" do
  it "print a polymorphic result alike, skipping a type named in it; the deploy refuses it" do
    r <- either (fail . Text.unpack . Text.unlines) pure (checkWithImports emptyVFS source)
    let checked = [ t | MkCheckErrorWithContext k@CheckInfo {} _ <- r.tcdErrors, t <- prettyCheckError k ]
        -- as l4/getExportedFunctions composes it (jl4-lsp/app/LSP/L4/Handlers.hs)
        inspected =
          [ s.returnType
          | s <- map (Inspector.exportedFunctionToSummary (declaresFromModule r.tcdModule))
                   (Export.enrichReturnTypes r.tcdEntityInfo (Export.getExportedFunctions r.tcdModule))
          ]
    compiled <- withLog \logger -> compileBundle logger "display-names" (Map.singleton "approve.l4" source)
    refusal <- case fst compiled of
      Left why -> pure why
      Right (_, meta) -> fail ("deployed: " <> show [ f.fsReturnType | f <- meta.metaFunctions ])
    (checked, inspected) `shouldBe` (["FUNCTION FROM b TO a"], ["FUNCTION FROM b TO a"])
    refusal `shouldSatisfy` Text.isInfixOf "its result is a function"

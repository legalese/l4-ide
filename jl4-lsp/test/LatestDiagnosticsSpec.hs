-- | 'LSP.L4.Oneshot.latestDiagnostics' and 'diagnosticsOf', which the CLI and
-- the golden suite use to print each file's diagnostics once
-- (smucclaw/l4-ide#1082).
module LatestDiagnosticsSpec (spec) where

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import LSP.L4.Oneshot (Log (..), diagnosticsOf, latestDiagnostics)
import Language.LSP.Protocol.Types (Uri (..), toNormalizedUri)
import Test.Hspec

spec :: Spec
spec = describe "latestDiagnostics" do
  let a = toNormalizedUri (Uri "file:///a.l4")
      b = toNormalizedUri (Uri "file:///b.l4")

  it "keeps only the last list of each file, where it falls, and every other message in order" $
    latestDiagnostics
      [ (Just a, "a1"), (Nothing, "x"), (Just b, "b1"), (Just a, "a2"), (Nothing, "y"), (Just b, "b2") ]
      `shouldBe` ["x", "a2", "y", "b2"]

  -- A file's last list can be empty. It is kept as it was logged (the header
  -- with nothing under it) and still replaces the lists before it, so no
  -- diagnostic that was withdrawn is printed.
  it "keeps a file's last list when it is empty, and drops the earlier ones" $
    latestDiagnostics [ (Just a, "a1 with a warning"), (Nothing, "x"), (Just a, "a2 empty") ]
      `shouldBe` ["x", "a2 empty"]

  it "keys an empty list by its file, from either recorder it arrives through" $ do
    diagnosticsOf (ShakeLog (Shake.LogDiagsDiffButNoLspEnv a [])) `shouldBe` Just a
    diagnosticsOf (RulesLog (Rules.ShakeLog (Shake.LogDiagsDiffButNoLspEnv b []))) `shouldBe` Just b
    diagnosticsOf (ShakeLog Shake.LogSessionInitialised) `shouldBe` Nothing
